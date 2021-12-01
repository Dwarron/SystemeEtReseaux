#!/bin/bash

numeroJoueur=$1			#numero du joueur passe en parametre dans le gestionnaire du jeu
partieFini=false		#boolean pour savoir si la partie est finie
topDepart=false			#boolean pour lancer la partie
cartesJoueur=()			#les cartes que le joueur possede
carteCourante=0			#la carte joué par le joueur

echo Vous êtes le joueur de numero : $numeroJoueur

echo Entrez votre Nom :
read nomJoueur

echo Entrez votre Prenom :
read prenomJoueur

#methode qui recupere les cartes 
waitCartes()
{
	onAttend=true
	while [ $onAttend == "true" ]
	do
		#permet de recevoir les cartes dans l'ordre des joueurs
		sleep $numeroJoueur
	
		#Envoie au gestionnaire du jeu que le joueur a recu les cartes
		echo "Joueur $numeroJoueur a recu ses cartes." | nc localhost 9091 2> /dev/null | echo "Vous avez reçu vos cartes" & onAttend=false
	done
	
	for i in $(eval echo {1..$(wc -w tmp/cartePartie | cut -d" " -f1)}); #nombre d'élément dans le fichier
	do	
		cartesJoueur+=($(echo $(cat tmp/cartePartie) | cut -d" " -f$i))	
	done
	echo "" > tmp/cartePartie
}

#methode qui attend le top depart
waitTopDepart()
{
	#on attend le top depart
	echo "Joueur $numeroJoueur a recu le top depart." | nc -l -p 9092 | echo "Attente du top départ."
}

#methode qui retire la carte envoyer 
retireCarte()
{
	carteRetirer=$1		 #indice de la carte a retirer 
	cartesTemp=()		 #tableau temporaire 
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesTemp 
	
	#on copie les cartes du joueur
	cartesTemp=("${cartesJoueur[@]}")
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesJoueur
	
	#recupere les bonnes valeurs 
	for i in $(eval echo {0..$((${#cartesTemp[*]} - 1))});
	do	
		if (( "$carteRetirer" != ${cartesTemp[$i]} ));
		then
			cartesJoueur+=(${cartesTemp[$i]})	
		fi
	done
}

ecrireCarteJouer()
{
	while [ $partieFini == "false" ]
	do
		#si le fichier tmp/carteJouer n'est pas vide
		if [ $(wc -w tmp/carteJouer | cut -d" " -f1) != 0 ];
		then
			cat tmp/carteJouer
			sleep 1
			cat "" > tmp/carteJouer
		fi
	done
}

finGame()
{
	if [ "$(echo $(cat tmp/finGame) | cut -d" " -f1)" == "fin" ];
	then
		tail -n 1 tmp/finGame
		partiFini=true
		exit 1
	fi
}

startGame()
{
	#avant de commencer la partie on attend les cartes
	waitCartes
	
	#quand on a recu les cartes on attend le top depart
	waitTopDepart
	
	#on lance la methode en tache de fond pour afficher chez tous le monde que tel joueur a jouer tel carte
	#ecrireCarteJouer &
	
	while [ $partieFini == "false" ]
	do
		#on verifie si le joueur a encores des cartes
		if (( ${#cartesJoueur[*]} == 0 ));
		then
			echo Vous avez jouer toutes vos cartes, attendez la fin de la manche.
			
			#apres chaque manche on verifie si la partie est fini
			finGame 
			
			onAttend=true
			while [ $onAttend == "true" ]
			do
				#si le fichier tmp/redistribuer n'est pas vide, redistribution cartes
				if [ $(wc -w tmp/redistribuer | cut -d" " -f1) != 0 ];
				then
					#on reverifie ici avant de redistribuer les cartes
					finGame 
					echo "" > tmp/redistribuer
					onAttend=false
					waitCartes		#on attend de nouvelles cartes
				fi
				sleep 1
			done
		fi
		
		echo Vos cartes sont : ${cartesJoueur[*]}
		echo Choissisez une carte a jouer :
		read carteCourante 
		
		#parcours les cartes du joueur afin de verifer que la carte joué est bien presente dans le jeu
		for i in $(eval echo {0..$((${#cartesJoueur[*]} - 1))});
		do
			if (( "$carteCourante" == ${cartesJoueur[$i]} ));
			then			
				#ecrit la valeur de la carte dans carteAJouer
				echo $carteCourante > tmp/carteAJouer
				
				#ecrit le num du joueur dans numJoueur
				echo $numeroJoueur > tmp/numJoueur
				
				onAttend=true
				while [ $onAttend == "true" ]
				do
					echo "Joueur $numeroJoueur a jouer la carte $carteCourante" | nc localhost 9093 2> /dev/null | echo "Carte joue." & onAttend=false
				done
			
				#on enleve la carte des cartes disponible pour le joueur
				#on n'utilise pas sa : cartesJoueur=( "${cartesJoueur[*]/$carteCourante" )
				#car si la carte a retirer est 1, sa enlever tous les 1 
				#si on a (10 15 1 78 41) et qu'on veut jouer 1, on va avoir (0 5 78 4)
				retireCarte $carteCourante
				
				#on sort de force de la boucle car dans le cas ou on retire la premiere  
				#carte du tableau, le if va comparer des cases qui n'existe plus  					#et va donc donner une erreur
				break
			fi
		done
	done
}

startGame
